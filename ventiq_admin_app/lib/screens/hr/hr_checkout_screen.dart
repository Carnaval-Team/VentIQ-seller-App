import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../models/hr/hr_attendance.dart';
import '../../services/hr/hr_attendance_service.dart';
import '../../services/store_service.dart';
import '../../widgets/hr/hr_drawer.dart';

class HRCheckoutScreen extends StatefulWidget {
  const HRCheckoutScreen({super.key});

  @override
  State<HRCheckoutScreen> createState() => _HRCheckoutScreenState();
}

class _HRCheckoutScreenState extends State<HRCheckoutScreen> {
  bool _isLoading = true;
  bool _isSubmitting = false;
  int? _storeId;
  String? _userUuid;

  List<HRAttendance> _workingWorkers = [];
  final Set<int> _selectedIds = {};
  final Map<int, bool> _aplicaPPR = {};

  TimeOfDay _selectedTime = TimeOfDay.now();

  @override
  void initState() {
    super.initState();
    _initializeData();
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
      await _loadWorkers();
    } catch (e) {
      print('❌ Error inicializando checkout: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadWorkers() async {
    if (_storeId == null) return;
    setState(() => _isLoading = true);

    try {
      final workers = await HRAttendanceService.getWorkersCurrentlyWorking(_storeId!);
      if (mounted) {
        setState(() {
          _workingWorkers = workers;
          _selectedIds.clear();
          _aplicaPPR.clear();
          for (final w in workers) {
            _aplicaPPR[w.asistenciaId] = false;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error cargando trabajadores: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _toggleSelectAll(bool? value) {
    setState(() {
      if (value == true) {
        _selectedIds.addAll(_workingWorkers.map((w) => w.asistenciaId));
      } else {
        _selectedIds.clear();
      }
    });
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      helpText: 'Hora de Salida',
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  double _estimateTotal() {
    double total = 0;
    final now = DateTime.now();
    final horaSalida = DateTime(
      now.year, now.month, now.day,
      _selectedTime.hour, _selectedTime.minute,
    );

    for (final w in _workingWorkers) {
      if (!_selectedIds.contains(w.asistenciaId)) continue;
      if (w.horaEntrada == null) continue;
      final horas = horaSalida.difference(w.horaEntrada!).inMinutes / 60.0;
      final horasEfectivas = horas.clamp(0, 8).toDouble();
      total += horasEfectivas * w.salarioHora;
      if (_aplicaPPR[w.asistenciaId] == true) {
        total += w.pagoPorResultado;
      }
    }
    return total;
  }

  Future<void> _batchCheckout() async {
    if (_selectedIds.isEmpty || _storeId == null || _userUuid == null) return;

    setState(() => _isSubmitting = true);

    final now = DateTime.now();
    final horaSalida = DateTime(
      now.year, now.month, now.day,
      _selectedTime.hour, _selectedTime.minute,
    );

    // Ordenar IDs para mantener sincronizacion con array de aplica_pago
    final orderedIds = _selectedIds.toList()..sort();
    final aplicaPago = orderedIds.map((id) => _aplicaPPR[id] ?? false).toList();

    try {
      final count = await HRAttendanceService.batchCheckout(
        asistenciaIds: orderedIds,
        horaSalida: horaSalida,
        aplicaPago: aplicaPago,
        cerradoPor: _userUuid!,
      );

      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$count salida(s) registrada(s) exitosamente'),
            backgroundColor: AppColors.success,
          ),
        );
        await _loadWorkers();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
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
    final currencyFormat = NumberFormat('#,##0.00');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Firmar Salida',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 20),
        ),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadWorkers,
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Header con hora y seleccionar todos
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.white,
                  child: Column(
                    children: [
                      // TimePicker
                      InkWell(
                        onTap: _selectTime,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(10),
                            color: AppColors.background,
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.access_time, color: AppColors.primary),
                              const SizedBox(width: 12),
                              Text(
                                'Hora de salida: ${_selectedTime.format(context)}',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                              ),
                              const Spacer(),
                              const Icon(Icons.edit, size: 18, color: AppColors.textSecondary),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Seleccionar todos
                      Row(
                        children: [
                          Checkbox(
                            value: _workingWorkers.isNotEmpty &&
                                _selectedIds.length == _workingWorkers.length,
                            tristate: true,
                            onChanged: _toggleSelectAll,
                            activeColor: AppColors.primary,
                          ),
                          Text(
                            'Seleccionar Todos (${_workingWorkers.length})',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Lista de trabajadores trabajando
                Expanded(
                  child: _workingWorkers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_outline, size: 64, color: Colors.grey[300]),
                              const SizedBox(height: 12),
                              Text(
                                'No hay trabajadores con entrada abierta',
                                style: TextStyle(color: Colors.grey[500], fontSize: 15),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 8, bottom: 80),
                          itemCount: _workingWorkers.length,
                          itemBuilder: (context, index) {
                            final w = _workingWorkers[index];
                            final isSelected = _selectedIds.contains(w.asistenciaId);
                            final horasTransc = w.horasTranscurridas ?? 0;
                            final timeFormat = DateFormat('HH:mm');

                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              elevation: isSelected ? 2 : 1,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: isSelected ? AppColors.primary.withOpacity(0.5) : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: isSelected,
                                      onChanged: (val) {
                                        setState(() {
                                          if (val == true) {
                                            _selectedIds.add(w.asistenciaId);
                                          } else {
                                            _selectedIds.remove(w.asistenciaId);
                                          }
                                        });
                                      },
                                      activeColor: AppColors.primary,
                                    ),
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: AppColors.primary.withOpacity(0.1),
                                      child: Text(
                                        w.nombres.isNotEmpty ? w.nombres[0].toUpperCase() : '?',
                                        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            w.nombreCompleto,
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Row(
                                            children: [
                                              Icon(Icons.login, size: 12, color: Colors.grey[500]),
                                              const SizedBox(width: 4),
                                              Text(
                                                w.horaEntrada != null ? timeFormat.format(w.horaEntrada!) : '--:--',
                                                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                              ),
                                              const SizedBox(width: 8),
                                              Icon(Icons.timer, size: 12, color: Colors.grey[500]),
                                              const SizedBox(width: 4),
                                              Text(
                                                _formatDuration(horasTransc),
                                                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                '\$${w.salarioHora.toStringAsFixed(2)}/h',
                                                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Toggle PPR
                                    if (w.pagoPorResultado > 0)
                                      Column(
                                        children: [
                                          Text(
                                            'PPR',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: _aplicaPPR[w.asistenciaId] == true
                                                  ? AppColors.success
                                                  : Colors.grey[400],
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Switch(
                                            value: _aplicaPPR[w.asistenciaId] ?? false,
                                            onChanged: (val) {
                                              setState(() {
                                                _aplicaPPR[w.asistenciaId] = val;
                                              });
                                            },
                                            activeColor: AppColors.success,
                                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                        ],
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

      // Bottom bar con resumen y boton
      bottomNavigationBar: _selectedIds.isNotEmpty
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Resumen
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${_selectedIds.length} seleccionado(s)',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        Text(
                          'Estimado: \$${currencyFormat.format(_estimateTotal())}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _batchCheckout,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.warning,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Text(
                                'Firmar Salida (${_selectedIds.length} seleccionados)',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
