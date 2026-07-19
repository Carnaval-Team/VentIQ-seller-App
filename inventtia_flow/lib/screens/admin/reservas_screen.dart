import 'dart:typed_data';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart' show Share, XFile;
import 'dart:io';

import '../../config/app_theme.dart';
import '../../models/agenda.dart';
import '../../models/campo_adicional.dart';
import '../../models/entidad.dart';
import '../../models/servicio.dart';
import '../../services/agenda_admin_service.dart';
import '../../services/agenda_service.dart';
import '../../services/auth_service.dart';
import '../../services/catalogo_service.dart';
import '../../utils/precio_reserva.dart';
import '../../utils/telefono_contacto.dart';
import '../../widgets/datos_adicionales_form.dart';
import '../../widgets/totales_datos_adicionales.dart';
import '../../widgets/totales_recurso_turno.dart';
import '../../widgets/cancelado_ribbon.dart';
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
  bool _filtrosExpanded = false;

  // Filtros (misma usabilidad que la vista de vendedor: un día + filtros colapsables)
  Local? _localFiltro;
  LocalServicio? _lsFiltro;
  late DateTime _fecha;
  int? _idEstadoFiltro;

  List<Local> _locales = [];
  List<LocalServicio> _localServicios = [];
  List<EstadoAgenda> _estados = [];

  final _fmt = DateFormat('dd/MM/yyyy');
  final _fmtDiaSemana = DateFormat('EEEE', 'es');
  final _fmtHora = DateFormat('dd/MM/yyyy HH:mm');

  DateTime get _desde => DateTime(_fecha.year, _fecha.month, _fecha.day);
  DateTime get _hasta =>
      DateTime(_fecha.year, _fecha.month, _fecha.day, 23, 59, 59);

  bool get _esHoy {
    final now = DateTime.now();
    return _fecha.year == now.year &&
        _fecha.month == now.month &&
        _fecha.day == now.day;
  }

  /// ¿La reserva se puede confirmar como consumida? Las activas siempre; las
  /// canceladas solo si su fecha es de hoy o anterior (aún se puede sellar el
  /// consumo de un servicio ya prestado que se había cancelado).
  bool _puedeCompletar(Agenda r) {
    final esCancelada = r.estado?.esCancelado == true;
    final esCompletada = r.estado?.esCompletado == true;
    if (esCompletada) return false;
    if (!esCancelada) return true; // activa (Reservado)
    final now = DateTime.now();
    final hoy = DateTime(now.year, now.month, now.day);
    final f = r.fechaHoraReserva;
    final diaReserva = DateTime(f.year, f.month, f.day);
    return !diaReserva.isAfter(hoy);
  }

  /// ¿Se puede descancelar (reactivar a Reservado)? Solo reservas canceladas
  /// cuya fecha sea de hoy o futura (no tiene sentido reactivar una vencida).
  bool _puedeDescancelar(Agenda r) {
    if (r.estado?.esCancelado != true) return false;
    final now = DateTime.now();
    final hoy = DateTime(now.year, now.month, now.day);
    final f = r.fechaHoraReserva;
    final diaReserva = DateTime(f.year, f.month, f.day);
    return !diaReserva.isBefore(hoy);
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fecha = DateTime(now.year, now.month, now.day);
    _loadFiltros();
  }

  Future<void> _loadFiltros() async {
    final results = await Future.wait([
      CatalogoService.getLocalesByEntidad(widget.entidad.id),
      AgendaService.getEstados(),
    ]);
    if (!mounted) return;
    final estados = results[1] as List<EstadoAgenda>;
    final reservado = estados.firstWhere(
      (e) => e.nombre.toLowerCase() == 'reservado',
      orElse: () => estados.isNotEmpty
          ? estados.first
          : EstadoAgenda(id: 1, nombre: 'reservado'),
    );
    setState(() {
      _locales = results[0] as List<Local>;
      _estados = estados;
      _idEstadoFiltro = reservado.id;
    });
    await _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final uuid = await AuthService.getCurrentUserId();
      if (uuid == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo obtener el usuario autenticado'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      final data = await AgendaAdminService.listarAgendas(
        uuidUsuario: uuid,
        idEntidad: widget.entidad.id,
        idLocal: _localFiltro?.id,
        idLocalServicio: _lsFiltro?.id,
        idEstado: _idEstadoFiltro,
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

  void _irDia(int delta) {
    if (_loading) return;
    setState(() => _fecha = _fecha.add(Duration(days: delta)));
    _load();
  }

  Future<void> _pickFecha() async {
    if (_loading) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2024),
      lastDate: DateTime(2028),
    );
    if (picked != null) {
      setState(
          () => _fecha = DateTime(picked.year, picked.month, picked.day));
      _load();
    }
  }

  void _irHoy() {
    if (_loading) return;
    final now = DateTime.now();
    setState(() => _fecha = DateTime(now.year, now.month, now.day));
    _load();
  }

  void _resetFiltros() {
    if (_loading) return;
    final reservado = _estados.firstWhere(
      (e) => e.nombre.toLowerCase() == 'reservado',
      orElse: () => _estados.isNotEmpty
          ? _estados.first
          : EstadoAgenda(id: 1, nombre: 'reservado'),
    );
    setState(() {
      _localFiltro = null;
      _lsFiltro = null;
      _localServicios = [];
      _idEstadoFiltro = reservado.id;
      _filtrosExpanded = false;
    });
    _load();
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
    // Estado 2 = Cancelado. La RPC notifica al cliente y libera la capacidad.
    await _cambiarEstado(reserva, 2, 'Reserva cancelada y cliente notificado');
  }

  Future<void> _descancelarReserva(Agenda reserva) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reactivar reserva'),
        content: Text(
          '¿Reactivar la reserva de '
          '${reserva.cliente?.nombreCompleto ?? 'este cliente'} '
          'para el servicio ${reserva.localServicio?.servicio?.nombre ?? ''}?'
          '\n\nVolverá a estado Reservado y ocupará capacidad de nuevo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
            child: const Text('Sí, reactivar'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    // Estado 1 = Reservado. La RPC re-consume la capacidad y notifica al cliente.
    await _cambiarEstado(reserva, 1, 'Reserva reactivada y cliente notificado');
  }

  Future<void> _completarReserva(Agenda reserva) async {
    final eraCancelada = reserva.estado?.esCancelado == true;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar consumo'),
        content: Text(
          '¿Confirmar que el cliente consumió la reserva de '
          '${reserva.cliente?.nombreCompleto ?? 'este cliente'} '
          'para el servicio ${reserva.localServicio?.servicio?.nombre ?? ''}?'
          '${eraCancelada ? '\n\nEsta reserva estaba cancelada; al confirmar se reactiva como completada y vuelve a ocupar capacidad.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
            child: const Text('Sí, confirmar'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    // Estado 3 = Completado.
    await _cambiarEstado(
        reserva,
        3,
        eraCancelada
            ? 'Reserva reactivada y marcada como completada'
            : 'Consumo de reserva confirmado');
  }

  /// Cambia el estado de una reserva vía RPC y refresca. [idEstado] 1=Reservado, 2=Cancelado, 3=Completado.
  Future<void> _cambiarEstado(Agenda reserva, int idEstado, String okMsg) async {
    setState(() => _loading = true);
    try {
      await AgendaAdminService.marcarEstadoAgenda(
        idAgenda: reserva.id,
        idEstado: idEstado,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(okMsg), backgroundColor: AppTheme.success),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}'),
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
    if (_loading) return;
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

  String _precioExport(Agenda r) {
    if (r.precioTotal == null || r.precioTotal! <= 0) return '-';
    return PrecioReserva.formatear(r.precioTotal!, r.moneda ?? 'USD');
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
                  'Nombre', 'Apellidos', 'CI', 'Telefono', 'Cant.', 'Precio',
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
                    _precioExport(r),
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
      'Nombre', 'Apellidos', 'CI', 'Telefono', 'Cantidad', 'Precio',
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
          _precioExport(ag),
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
    parts.add('Fecha: ${_fmt.format(_fecha)}');
    return parts.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      absorbing: _loading,
      child: Scaffold(
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
              onPressed: _reservas.isEmpty || _loading ? null : _exportPdf,
            ),
            IconButton(
              icon: const Icon(Icons.table_chart_outlined),
              tooltip: 'Exportar Excel',
              onPressed: _reservas.isEmpty || _loading ? null : _exportExcel,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _load,
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                _buildBarraFecha(),
                _buildFiltrosColapsables(),
                const Divider(height: 1),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragEnd: (details) {
                      if (_loading) return;
                      final v = details.primaryVelocity ?? 0;
                      if (v < -200) _irDia(1);
                      if (v > 200) _irDia(-1);
                    },
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _reservas.isEmpty
                            ? _buildEmpty()
                            : RefreshIndicator(
                                onRefresh: _load,
                                child: _buildTabla(),
                              ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBarraFecha() {
    final diaSemana = _fmtDiaSemana.format(_fecha);
    final diaCapitalizado =
        diaSemana[0].toUpperCase() + diaSemana.substring(1);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Día anterior',
            onPressed: _loading ? null : () => _irDia(-1),
            color: AppTheme.primary,
          ),
          Expanded(
            child: InkWell(
              onTap: _pickFecha,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Column(
                  children: [
                    Text(
                      _fmt.format(_fecha),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _loading
                            ? AppTheme.textSecondary
                            : AppTheme.textPrimary,
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          diaCapitalizado,
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.textSecondary),
                        ),
                        if (_esHoy) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Hoy',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Día siguiente',
            onPressed: _loading ? null : () => _irDia(1),
            color: AppTheme.primary,
          ),
          if (!_esHoy)
            TextButton(
              onPressed: _loading ? null : _irHoy,
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: const Text('Hoy',
                  style: TextStyle(fontSize: 12, color: AppTheme.primary)),
            ),
        ],
      ),
    );
  }

  Widget _buildFiltrosColapsables() {
    final hayFiltrosActivos =
        _localFiltro != null || _lsFiltro != null || _idEstadoFiltro != null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: _loading
                ? null
                : () =>
                    setState(() => _filtrosExpanded = !_filtrosExpanded),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.filter_list,
                    size: 16,
                    color: hayFiltrosActivos
                        ? AppTheme.primary
                        : AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      () {
                        final parts = [
                          if (_localFiltro != null) _localFiltro!.nombre,
                          if (_lsFiltro != null)
                            _lsFiltro!.servicio?.nombre ?? '',
                          if (_idEstadoFiltro != null)
                            _estados
                                .firstWhere((e) => e.id == _idEstadoFiltro,
                                    orElse: () =>
                                        EstadoAgenda(id: 0, nombre: ''))
                                .nombre,
                        ].where((s) => s.isNotEmpty).join(' · ');
                        return parts.isNotEmpty ? parts : 'Filtros';
                      }(),
                      style: TextStyle(
                        fontSize: 12,
                        color: hayFiltrosActivos
                            ? AppTheme.primary
                            : AppTheme.textSecondary,
                        fontWeight: hayFiltrosActivos
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (_reservas.isNotEmpty) ...[
                    TotalesRecursoTurnoBadge(reservas: _reservas),
                    const SizedBox(width: 8),
                    Text(
                      '${_reservas.length} reserva${_reservas.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary),
                    ),
                  ],
                  const SizedBox(width: 6),
                  if (hayFiltrosActivos)
                    GestureDetector(
                      onTap: _loading ? null : _resetFiltros,
                      child: const Icon(Icons.clear,
                          size: 16, color: AppTheme.textSecondary),
                    )
                  else
                    Icon(
                      _filtrosExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 18,
                      color: AppTheme.textSecondary,
                    ),
                ],
              ),
            ),
          ),
          if (_filtrosExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<Local?>(
                          value: _localFiltro,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Local',
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem(
                                value: null, child: Text('Todos')),
                            ..._locales.map((l) => DropdownMenuItem(
                                value: l,
                                child: Text(l.nombre,
                                    overflow: TextOverflow.ellipsis))),
                          ],
                          onChanged: _loading ? null : _onLocalChange,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<LocalServicio?>(
                          value: _lsFiltro,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Servicio',
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
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
                          onChanged: _loading
                              ? null
                              : (v) {
                                  setState(() {
                                    _lsFiltro = v;
                                    _filtrosExpanded = false;
                                  });
                                  _load();
                                },
                        ),
                      ),
                    ],
                  ),
                  if (_estados.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _EstadoChip(
                          label: 'Todos',
                          selected: _idEstadoFiltro == null,
                          onTap: _loading
                              ? null
                              : () {
                                  setState(() {
                                    _idEstadoFiltro = null;
                                    _filtrosExpanded = false;
                                  });
                                  _load();
                                },
                        ),
                        ..._estados.map((e) => _EstadoChip(
                              label: e.nombre[0].toUpperCase() +
                                  e.nombre.substring(1),
                              selected: _idEstadoFiltro == e.id,
                              onTap: _loading
                                  ? null
                                  : () {
                                      setState(() {
                                        _idEstadoFiltro = e.id;
                                        _filtrosExpanded = false;
                                      });
                                      _load();
                                    },
                            )),
                      ],
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTabla() {
    final grupos = _agruparPorLocal();
    final cols = _columnasDatos(_reservas);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        TotalesPanel(reservas: _reservas),
        for (final entry in grupos.entries) ...[
          if (grupos.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 6),
              child: Row(
                children: [
                  const Icon(Icons.store_outlined, size: 14, color: AppTheme.primary),
                  const SizedBox(width: 6),
                  Text(entry.key,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppTheme.primary)),
                ],
              ),
            ),
          ...entry.value.map((r) => _buildReservaCard(r, cols)),
        ],
      ],
    );
  }

  Widget _buildReservaCard(Agenda r, List<({String clave, String etiqueta})> cols) {
    final esTercero = r.reservadoPor != null &&
        r.uuidUsuario != null &&
        r.reservadoPor != r.uuidUsuario;
    final esCancelada = r.estado?.esCancelado == true;
    final esCompletada = r.estado?.esCompletado == true;
    final esActiva = !esCancelada && !esCompletada; // 'Reservado'
    final telefono = _datoCliente(r, 'telefono');

    final card = Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        // Completada: borde azul sutil. Resto: borde gris tenue.
        side: BorderSide(
          color: esCompletada
              ? AppTheme.primary.withValues(alpha: 0.55)
              : Colors.grey.shade200,
          width: esCompletada ? 1.2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    r.localServicio?.servicio?.nombre ?? '-',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppTheme.textPrimary),
                  ),
                ),
                Text(
                  _fmt.format(r.fechaHoraReserva),
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Divider(height: 1),
            const SizedBox(height: 6),
            _infoRow('Nombre', '${_datoCliente(r, 'nombre')} ${_datoCliente(r, 'apellidos')}'),
            _infoRow('CI', _datoCliente(r, 'ci')),
            if (telefono != '-' && telefono.isNotEmpty)
              _infoRowWidget(
                'Teléfono',
                GestureDetector(
                  onTap: () => TelefonoContacto.mostrarOpciones(context, telefono),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.phone, size: 12, color: AppTheme.primary),
                      const SizedBox(width: 4),
                      Text(telefono,
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.primary,
                              decoration: TextDecoration.underline)),
                    ],
                  ),
                ),
              )
            else
              _infoRow('Teléfono', '-'),
            if (r.turnoNombre != null)
              _infoRow(
                'Turno',
                r.recursoNombre != null
                    ? '${r.recursoNombre} · ${r.turnoNombre}'
                    : r.turnoNombre!,
              ),
            if (r.cantidad > 1) _infoRow('Cantidad', '${r.cantidad}'),
            if (r.precioTotal != null && r.precioTotal! > 0)
              _infoRow(
                'Precio',
                PrecioReserva.formatear(
                    r.precioTotal!, r.moneda ?? 'USD'),
              ),
            if (esTercero) _infoRow('Para tercero', 'Sí'),
            for (final c in cols)
              if (_valorDato(r, c.clave) != '-')
                _infoRow(c.etiqueta, _valorDato(r, c.clave)),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Editar'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () => _editarReserva(r),
                ),
                if (_puedeCompletar(r))
                  TextButton.icon(
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('Confirmar consumido'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () => _completarReserva(r),
                  ),
                if (_puedeDescancelar(r))
                  TextButton.icon(
                    icon: const Icon(Icons.restore, size: 16),
                    label: const Text('Reactivar'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () => _descancelarReserva(r),
                  ),
                if (esActiva)
                  TextButton.icon(
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('Cancelar'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.error,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () => _cancelarReserva(r),
                  ),
                if (!esActiva && !_puedeCompletar(r) && !_puedeDescancelar(r))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      esCompletada ? 'Completada' : 'Cancelada',
                      style: TextStyle(
                          fontSize: 11,
                          color: esCompletada ? AppTheme.primary : AppTheme.error,
                          fontWeight: FontWeight.w600,
                          fontStyle: FontStyle.italic),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );

    // Cancelada: cinta diagonal roja "CANCELADO" sobre la tarjeta. Sigue
    // permitiendo editar y, si es de hoy o antes, confirmar consumo.
    if (esCancelada) {
      return CanceladoRibbon(child: card);
    }
    return card;
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 90,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
            ),
          ],
        ),
      );

  Widget _infoRowWidget(String label, Widget widget) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 90,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary)),
            ),
            widget,
          ],
        ),
      );

  Widget _buildEmpty() {
    return SizedBox.expand(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.18),
            Center(
              child: Column(
                children: [
                  Icon(Icons.event_busy_outlined,
                      size: 64,
                      color: AppTheme.textSecondary.withOpacity(0.35)),
                  const SizedBox(height: 12),
                  const Text(
                    'Sin reservas para los filtros aplicados',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _fmt.format(_fecha),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Desliza para cambiar de día',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EstadoChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const _EstadoChip({required this.label, required this.selected, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary
              : AppTheme.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppTheme.primary
                : AppTheme.primary.withOpacity(0.2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppTheme.primary,
          ),
        ),
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
        onTap: () => TelefonoContacto.mostrarOpciones(context, telefono),
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
