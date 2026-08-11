import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../models/hr/hr_attendance.dart';
import '../../services/hr/hr_attendance_service.dart';
import '../../services/store_service.dart';
import '../../widgets/hr/hr_drawer.dart';
import '../../widgets/hr/hr_modalidad_badge.dart';

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
  // Cantidad editable a pagar por trabajador (key = asistenciaId).
  // Su unidad depende de la modalidad: HORAS si cobra por hora, DÍAS si
  // cobra por día. Un día no equivale a 8h ni a 24h.
  final Map<int, TextEditingController> _cantidadControllers = {};

  TimeOfDay _selectedTime = TimeOfDay.now();

  @override
  void dispose() {
    for (final c in _cantidadControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Horas calculadas (raw) entre la hora de entrada del trabajador y la hora
  /// de salida global del TimePicker. Sirve como valor inicial sugerido.
  double _calcHorasRaw(HRAttendance w) {
    if (w.horaEntrada == null) return 0;
    final now = DateTime.now();
    final horaSalida = DateTime(
      now.year, now.month, now.day,
      _selectedTime.hour, _selectedTime.minute,
    );
    final diff = horaSalida.difference(w.horaEntrada!).inMinutes / 60.0;
    return diff < 0 ? 0 : diff;
  }

  /// Cantidad sugerida al abrir la pantalla, en la unidad de la modalidad:
  /// por día siempre 1 jornada completa; por hora, las horas transcurridas.
  double _cantidadSugerida(HRAttendance w) =>
      w.esPorDia ? 1.0 : _calcHorasRaw(w);

  /// Cantidad que el usuario decidió pagar (días u horas según modalidad).
  /// Si no ha editado el campo, usa el valor sugerido.
  double _cantidadParaTrabajador(HRAttendance w) {
    final ctrl = _cantidadControllers[w.asistenciaId];
    if (ctrl == null || ctrl.text.trim().isEmpty) return _cantidadSugerida(w);
    final parsed = double.tryParse(ctrl.text.replaceAll(',', '.'));
    return parsed == null || parsed < 0 ? 0 : parsed;
  }

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
          // Limpiar controllers viejos
          for (final c in _cantidadControllers.values) {
            c.dispose();
          }
          _cantidadControllers.clear();
          for (final w in workers) {
            _aplicaPPR[w.asistenciaId] = false;
            // Precargar la cantidad sugerida: 1 día completo o las horas
            // transcurridas, según la modalidad del trabajador.
            _cantidadControllers[w.asistenciaId] = TextEditingController(
              text: _cantidadSugerida(w).toStringAsFixed(2),
            );
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
      setState(() {
        _selectedTime = picked;
        // Recalcular las horas sugeridas. A quien cobra por día no le afecta
        // la hora de salida: sus días a pagar no se derivan del tiempo.
        for (final w in _workingWorkers) {
          if (w.esPorDia) continue;
          final ctrl = _cantidadControllers[w.asistenciaId];
          if (ctrl != null) {
            ctrl.text = _calcHorasRaw(w).toStringAsFixed(2);
          }
        }
      });
    }
  }

  double _estimateTotal() {
    double total = 0;

    for (final w in _workingWorkers) {
      if (!_selectedIds.contains(w.asistenciaId)) continue;
      if (w.horaEntrada == null) continue;
      // salarioHora es la tarifa de su modalidad ($/hora o $/día), así que
      // el cálculo es el mismo: cantidad a pagar x tarifa.
      total += _cantidadParaTrabajador(w) * w.salarioHora;
      // El PPR es un bono fijo por jornada: no se multiplica por la cantidad.
      if (_aplicaPPR[w.asistenciaId] == true) {
        total += w.pagoPorResultado;
      }
    }
    return total;
  }

  Future<void> _batchCheckout() async {
    if (_selectedIds.isEmpty || _storeId == null || _userUuid == null) return;

    setState(() => _isSubmitting = true);

    // Cierre individual por trabajador para que cada uno pueda cerrarse con
    // una cantidad distinta. El backend interpreta la cantidad según la
    // modalidad: horas a pagar (ajusta hora_salida) o días a pagar.
    int okCount = 0;
    final List<String> errores = [];

    // Hora de salida real seleccionada en el TimePicker. Solo se usa tal cual
    // en modalidad día; en modalidad hora el backend la recalcula.
    final now = DateTime.now();
    final horaSalidaReal = DateTime(
      now.year, now.month, now.day,
      _selectedTime.hour, _selectedTime.minute,
    );

    for (final w in _workingWorkers) {
      if (!_selectedIds.contains(w.asistenciaId)) continue;
      if (w.horaEntrada == null) {
        errores.add('${w.nombreCompleto}: sin hora de entrada');
        continue;
      }

      final cantidad = _cantidadParaTrabajador(w);
      if (cantidad <= 0) {
        errores.add(
          '${w.nombreCompleto}: ${w.tipoSalario.unidadPlural} inválidas',
        );
        continue;
      }

      try {
        final count = await HRAttendanceService.batchCheckout(
          asistenciaIds: [w.asistenciaId],
          horaSalida: horaSalidaReal,
          aplicaPago: [_aplicaPPR[w.asistenciaId] ?? false],
          cerradoPor: _userUuid!,
          cantidad: [cantidad],
        );
        okCount += count;
      } catch (e) {
        errores.add('${w.nombreCompleto}: $e');
      }
    }

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (errores.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$okCount salida(s) registrada(s) exitosamente'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$okCount cerradas, ${errores.length} con error:\n${errores.take(3).join("\n")}',
            ),
            backgroundColor: errores.length == _selectedIds.length
                ? AppColors.error
                : AppColors.warning,
            duration: const Duration(seconds: 6),
          ),
        );
      }
      await _loadWorkers();
    }
  }

  String _formatDuration(double hours) {
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    return '${h}h ${m}m';
  }

  Widget _modalidadBadge(HRAttendance w) =>
      HRModalidadBadge(tipoSalario: w.tipoSalario);

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
                                              // Tarifa de su modalidad: $/h o $/d
                                              Text(
                                                w.tarifaFormatted,
                                                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                              ),
                                              if (w.esPorDia) ...[
                                                const SizedBox(width: 6),
                                                _modalidadBadge(w),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          // Campo editable: horas o días a pagar según modalidad
                                          Row(
                                            children: [
                                              const Icon(Icons.edit_calendar, size: 12, color: AppColors.primary),
                                              const SizedBox(width: 4),
                                              Text(
                                                w.tipoSalario.labelCantidadAPagar,
                                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                                              ),
                                              const SizedBox(width: 6),
                                              SizedBox(
                                                width: 70,
                                                height: 32,
                                                child: TextField(
                                                  controller: _cantidadControllers[w.asistenciaId],
                                                  enabled: isSelected,
                                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                                  decoration: InputDecoration(
                                                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                                    isDense: true,
                                                    border: OutlineInputBorder(
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    suffixText: w.tipoSalario.unidadCorta,
                                                    suffixStyle: const TextStyle(fontSize: 10),
                                                  ),
                                                  onChanged: (_) => setState(() {}),
                                                ),
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
