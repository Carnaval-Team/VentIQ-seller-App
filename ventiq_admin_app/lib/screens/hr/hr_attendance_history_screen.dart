import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../models/hr/hr_attendance.dart';
import '../../services/hr/hr_attendance_service.dart';
import '../../services/store_service.dart';
import '../../widgets/hr/hr_drawer.dart';

class HRAttendanceHistoryScreen extends StatefulWidget {
  const HRAttendanceHistoryScreen({super.key});

  @override
  State<HRAttendanceHistoryScreen> createState() =>
      _HRAttendanceHistoryScreenState();
}

class _HRAttendanceHistoryScreenState
    extends State<HRAttendanceHistoryScreen> {
  bool _isLoading = true;
  int? _storeId;
  String? _userUuid;

  List<HRAttendance> _records = [];
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  late DateTime _fechaDesde;
  late DateTime _fechaHasta;

  final _dateFormat = DateFormat('dd/MM/yyyy');
  final _timeFormat = DateFormat('HH:mm');
  final _currencyFormat = NumberFormat('#,##0.00');

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fechaDesde = DateTime(now.year, now.month, 1);
    _fechaHasta = DateTime(now.year, now.month + 1, 0);
    _initializeData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    try {
      final storeData = await StoreService.getWorkerRequiredData();
      if (storeData == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      setState(() {
        _storeId = storeData['storeId'] as int?;
        _userUuid = storeData['userUuid'] as String?;
      });
      await _loadRecords();
    } catch (e) {
      print('❌ Error inicializando historial: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadRecords() async {
    if (_storeId == null) return;
    setState(() => _isLoading = true);
    try {
      final records = await HRAttendanceService.getAttendanceHistory(
        _storeId!,
        fechaDesde: _fechaDesde,
        fechaHasta: _fechaHasta,
      );
      if (mounted) {
        setState(() {
          _records = records;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error cargando historial: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
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
    );
    if (picked != null) {
      setState(() {
        _fechaDesde = picked.start;
        _fechaHasta = picked.end;
      });
      await _loadRecords();
    }
  }

  List<HRAttendance> get _filteredRecords {
    if (_searchQuery.isEmpty) return _records;
    final q = _searchQuery.toLowerCase();
    return _records.where((r) {
      return r.nombreCompleto.toLowerCase().contains(q) ||
          (r.rolNombre?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  // ---------------------------------------------------------------
  // Confirmación en dos pasos para eliminar un día de trabajo.
  // Paso 1: el usuario escribe "ELIMINAR".
  // Paso 2: botón Sí / No.
  // ---------------------------------------------------------------
  Future<void> _confirmAndDelete(HRAttendance record) async {
    // --- Paso 1: escribir "ELIMINAR" ---
    final typingController = TextEditingController();
    bool step1Confirmed = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final matchesWord =
                typingController.text.trim().toUpperCase() == 'ELIMINAR';
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red),
                  SizedBox(width: 8),
                  Text(
                    'Confirmar eliminación',
                    style: TextStyle(fontSize: 17),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                          fontSize: 14, color: Colors.black87),
                      children: [
                        const TextSpan(
                            text: 'Vas a eliminar el día de trabajo de '),
                        TextSpan(
                          text: record.nombreCompleto,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const TextSpan(text: ' del '),
                        TextSpan(
                          text: record.horaEntrada != null
                              ? _dateFormat.format(record.horaEntrada!)
                              : '—',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Escribe ELIMINAR para continuar:',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: typingController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'ELIMINAR',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      errorText: typingController.text.isNotEmpty && !matchesWord
                          ? 'Escribe exactamente: ELIMINAR'
                          : null,
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: matchesWord
                      ? () {
                          step1Confirmed = true;
                          Navigator.of(ctx).pop();
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.red.withOpacity(0.3),
                  ),
                  child: const Text('Continuar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!step1Confirmed || !mounted) return;

    // --- Paso 2: confirmación final Sí / No ---
    final finalConfirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.red),
            SizedBox(width: 8),
            Text('¿Eliminar este día?', style: TextStyle(fontSize: 17)),
          ],
        ),
        content: Text(
          '¿Estás seguro de que deseas eliminar el día de trabajo de '
          '${record.nombreCompleto}? '
          'Esta acción no se puede deshacer y '
          '${record.horasTrabajadas != null ? '${record.horasTrabajadas!.toStringAsFixed(2)} horas trabajadas y ' : ''}'
          'su salario correspondiente serán descontados del reporte.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No, cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sí, eliminar'),
          ),
        ],
      ),
    );

    if (finalConfirmed != true || !mounted) return;

    // --- Ejecutar la eliminación ---
    try {
      await HRAttendanceService.deleteAttendance(
        asistenciaId: record.asistenciaId,
        eliminadoPor: _userUuid ?? '',
        storeId: _storeId!,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Día de trabajo eliminado correctamente'),
            backgroundColor: AppColors.success,
          ),
        );
        await _loadRecords();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al eliminar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  String _formatDuration(double hours) {
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRecords;
    final totalDias = filtered.length;
    final totalHoras = filtered.fold<double>(
      0,
      (s, r) => s + (r.horasTrabajadas ?? 0),
    );
    final totalSalario = filtered.fold<double>(
      0,
      (s, r) => s + (r.salarioTotal ?? 0),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Historial de Asistencia',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600, fontSize: 20),
        ),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadRecords,
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
      body: Column(
        children: [
          // ── Header: selector de fechas + búsqueda ──────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              children: [
                // Selector de rango
                InkWell(
                  onTap: _selectDateRange,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(10),
                      color: AppColors.background,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.date_range, color: AppColors.primary),
                        const SizedBox(width: 10),
                        Text(
                          '${_dateFormat.format(_fechaDesde)}  →  ${_dateFormat.format(_fechaHasta)}',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                        const Spacer(),
                        const Icon(Icons.edit,
                            size: 16, color: AppColors.textSecondary),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Búsqueda
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Buscar trabajador o rol...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 10),
                    filled: true,
                    fillColor: AppColors.background,
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ],
            ),
          ),

          // ── KPI chips ─────────────────────────────────────────
          if (!_isLoading && filtered.isNotEmpty)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(
                children: [
                  _chip('$totalDias días', Icons.calendar_today,
                      AppColors.info),
                  const SizedBox(width: 8),
                  _chip(_formatDuration(totalHoras), Icons.access_time,
                      AppColors.primary),
                  const SizedBox(width: 8),
                  _chip(
                    '\$${_currencyFormat.format(totalSalario)}',
                    Icons.attach_money,
                    AppColors.success,
                  ),
                ],
              ),
            ),

          const Divider(height: 1),

          // ── Lista de registros ─────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.history,
                                size: 64, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'Sin resultados para "$_searchQuery"'
                                  : 'Sin registros en este período',
                              style: TextStyle(
                                  color: Colors.grey[500], fontSize: 15),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final r = filtered[index];
                          final isOpen = r.horaSalida == null;
                          final horas = r.horasTrabajadas ?? 0.0;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: isOpen
                                    ? AppColors.warning.withOpacity(0.5)
                                    : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Avatar
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor:
                                        AppColors.primary.withOpacity(0.1),
                                    child: Text(
                                      r.nombres.isNotEmpty
                                          ? r.nombres[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Nombre + badge activo
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                r.nombreCompleto,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 14,
                                                ),
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (isOpen) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppColors.warning
                                                      .withOpacity(0.15),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: const Text(
                                                  'Activo',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: AppColors.warning,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        // Rol + fecha
                                        Text(
                                          '${r.rolNombre ?? 'Sin rol'} · ${r.horaEntrada != null ? _dateFormat.format(r.horaEntrada!) : '—'}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        // Entrada / Salida / Horas
                                        Row(
                                          children: [
                                            _infoChip(
                                              Icons.login,
                                              r.horaEntrada != null
                                                  ? _timeFormat.format(
                                                      r.horaEntrada!)
                                                  : '—',
                                              Colors.green,
                                            ),
                                            const SizedBox(width: 8),
                                            _infoChip(
                                              Icons.logout,
                                              r.horaSalida != null
                                                  ? _timeFormat.format(
                                                      r.horaSalida!)
                                                  : '—',
                                              isOpen
                                                  ? Colors.grey
                                                  : Colors.orange,
                                            ),
                                            const SizedBox(width: 8),
                                            _infoChip(
                                              Icons.access_time,
                                              isOpen
                                                  ? 'En turno'
                                                  : _formatDuration(horas),
                                              AppColors.info,
                                            ),
                                            if (r.esPorDia) ...[
                                              const SizedBox(width: 8),
                                              _infoChip(
                                                Icons.today,
                                                r.cantidadPagadaFormatted,
                                                AppColors.primary,
                                              ),
                                            ],
                                          ],
                                        ),
                                        if (!isOpen) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            'Salario: \$${_currencyFormat.format(r.salarioTotal ?? 0)}  ·  ${r.tarifaFormatted}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),

                                  // Botón eliminar (solo registros cerrados)
                                  if (!isOpen)
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.red),
                                      tooltip: 'Eliminar día de trabajo',
                                      onPressed: () => _confirmAndDelete(r),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, IconData icon, Color color) {
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
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
