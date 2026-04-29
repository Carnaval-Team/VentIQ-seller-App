import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../models/hr/hr_attendance.dart';
import '../../services/hr/hr_attendance_service.dart';
import '../../services/store_service.dart';
import '../../widgets/hr/hr_drawer.dart';
import '../../widgets/hr/hr_worker_list_tile.dart';

class HRCheckinScreen extends StatefulWidget {
  const HRCheckinScreen({super.key});

  @override
  State<HRCheckinScreen> createState() => _HRCheckinScreenState();
}

class _HRCheckinScreenState extends State<HRCheckinScreen> {
  bool _isLoading = true;
  bool _isSubmitting = false;
  int? _storeId;
  String? _userUuid;

  List<HRAttendance> _availableWorkers = [];
  final Set<int> _selectedWorkerIds = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  TimeOfDay _selectedTime = TimeOfDay.now();

  @override
  void initState() {
    super.initState();
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
      await _loadWorkers();
    } catch (e) {
      print('❌ Error inicializando check-in: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadWorkers() async {
    if (_storeId == null) return;
    setState(() => _isLoading = true);

    try {
      final workers = await HRAttendanceService.getWorkersForCheckin(_storeId!);
      if (mounted) {
        setState(() {
          _availableWorkers = workers;
          _selectedWorkerIds.clear();
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

  List<HRAttendance> get _filteredWorkers {
    if (_searchQuery.isEmpty) return _availableWorkers;
    final query = _searchQuery.toLowerCase();
    return _availableWorkers.where((w) {
      return w.nombreCompleto.toLowerCase().contains(query) ||
          (w.rolNombre?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      helpText: 'Hora de Entrada',
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _registerCheckins() async {
    if (_selectedWorkerIds.isEmpty || _storeId == null || _userUuid == null) return;

    setState(() => _isSubmitting = true);

    final now = DateTime.now();
    final horaEntrada = DateTime(
      now.year, now.month, now.day,
      _selectedTime.hour, _selectedTime.minute,
    );

    int success = 0;
    int errors = 0;

    for (final workerId in _selectedWorkerIds) {
      try {
        await HRAttendanceService.registerCheckin(
          storeId: _storeId!,
          workerId: workerId,
          horaEntrada: horaEntrada,
          registradoPor: _userUuid!,
        );
        success++;
      } catch (e) {
        errors++;
        print('❌ Error registrando entrada trabajador $workerId: $e');
      }
    }

    if (mounted) {
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errors == 0
                ? '$success entrada(s) registrada(s) exitosamente'
                : '$success exitosa(s), $errors error(es)',
          ),
          backgroundColor: errors == 0 ? AppColors.success : AppColors.warning,
        ),
      );
      await _loadWorkers();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Firmar Entrada',
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
                // Barra de busqueda y hora
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.white,
                  child: Column(
                    children: [
                      // Search
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Buscar trabajador...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          filled: true,
                          fillColor: AppColors.background,
                        ),
                        onChanged: (value) => setState(() => _searchQuery = value),
                      ),
                      const SizedBox(height: 8),
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
                                'Hora de entrada: ${_selectedTime.format(context)}',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                              ),
                              const Spacer(),
                              const Icon(Icons.edit, size: 18, color: AppColors.textSecondary),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Lista de trabajadores
                Expanded(
                  child: _filteredWorkers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.people_outline, size: 64, color: Colors.grey[300]),
                              const SizedBox(height: 12),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'Sin resultados para "$_searchQuery"'
                                    : 'Todos los trabajadores ya ficharon entrada',
                                style: TextStyle(color: Colors.grey[500], fontSize: 15),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 8, bottom: 80),
                          itemCount: _filteredWorkers.length,
                          itemBuilder: (context, index) {
                            final worker = _filteredWorkers[index];
                            final isSelected = _selectedWorkerIds.contains(worker.trabajadorId);
                            return HRWorkerListTile(
                              nombre: worker.nombreCompleto,
                              rol: worker.rolNombre,
                              salarioHora: worker.salarioHora,
                              pagoPorResultado: worker.pagoPorResultado,
                              isSelected: isSelected,
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedWorkerIds.add(worker.trabajadorId);
                                  } else {
                                    _selectedWorkerIds.remove(worker.trabajadorId);
                                  }
                                });
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
      bottomNavigationBar: _selectedWorkerIds.isNotEmpty
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
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _registerCheckins,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
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
                          'Registrar Entrada (${_selectedWorkerIds.length} seleccionados)',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            )
          : null,
    );
  }
}
