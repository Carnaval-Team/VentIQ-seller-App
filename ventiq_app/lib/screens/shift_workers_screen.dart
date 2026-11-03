import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/shift_worker.dart';
import '../services/shift_workers_service.dart';
import '../services/turno_service.dart';
import '../utils/app_snackbar.dart';
import '../theme/ventiq_home_theme.dart';

class ShiftWorkersScreen extends StatefulWidget {
  const ShiftWorkersScreen({Key? key}) : super(key: key);

  @override
  State<ShiftWorkersScreen> createState() => _ShiftWorkersScreenState();
}

class _ShiftWorkersScreenState extends State<ShiftWorkersScreen> {
  bool _isLoading = true;
  bool _hasOpenShift = false;
  int? _currentShiftId;
  List<ShiftWorker> _shiftWorkers = [];
  final Set<int> _selectedWorkerIds = {};
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    _checkShiftAndLoadWorkers();
    _startUpdateTimer();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  /// Iniciar timer para actualizar horas trabajadas cada minuto
  void _startUpdateTimer() {
    _updateTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted && _shiftWorkers.any((w) => w.isActive)) {
        // Solo actualizar si hay trabajadores activos
        setState(() {
          // El rebuild recalculará las horas con _calculateCurrentHours
        });
      }
    });
  }

  Future<void> _checkShiftAndLoadWorkers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Verificar si hay turno abierto
      final turnoAbierto = await TurnoService.getTurnoAbierto();

      if (turnoAbierto == null) {
        setState(() {
          _hasOpenShift = false;
          _isLoading = false;
        });
        return;
      }

      final shiftId = turnoAbierto['id'] as int;

      setState(() {
        _hasOpenShift = true;
        _currentShiftId = shiftId;
      });

      // Cargar trabajadores del turno
      await _loadShiftWorkers();
    } catch (e) {
      print('❌ Error verificando turno: $e');
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        AppSnackBar.showPersistent(
          context,
          message: 'Error: $e',
          backgroundColor: Colors.red,
        );
      }
    }
  }

  Future<void> _loadShiftWorkers() async {
    if (_currentShiftId == null) return;

    try {
      final workers = await ShiftWorkersService.getShiftWorkers(
        _currentShiftId!,
      );

      setState(() {
        _shiftWorkers = workers;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error cargando trabajadores: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VentiqHomeTheme.surface,
      appBar: AppBar(
        backgroundColor: VentiqHomeTheme.primary,
        elevation: 0,
        title: const Text(
          'Trabajadores de Turno',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _checkShiftAndLoadWorkers,
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    VentiqHomeTheme.primary,
                  ),
                ),
              )
              : !_hasOpenShift
              ? _buildNoShiftView()
              : _buildWorkersView(),
      floatingActionButton:
          _hasOpenShift
              ? FloatingActionButton.extended(
                onPressed: _showAddWorkersDialog,
                backgroundColor: VentiqHomeTheme.primary,
                icon: const Icon(Icons.person_add, color: Colors.white),
                label: const Text(
                  'Agregar Trabajadores',
                  style: TextStyle(color: Colors.white),
                ),
              )
              : null,
    );
  }

  Widget _buildNoShiftView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_clock,
                size: 64,
                color: Colors.orange[700],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No hay turno abierto',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: VentiqHomeTheme.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Debes abrir un turno antes de poder gestionar trabajadores',
              style: TextStyle(
                fontSize: 14,
                color: VentiqHomeTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pushNamed(context, '/apertura').then((_) {
                  _checkShiftAndLoadWorkers();
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: VentiqHomeTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.lock_open),
              label: const Text(
                'Ir a Apertura',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkersView() {
    if (_shiftWorkers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.people_outline,
                size: 64,
                color: VentiqHomeTheme.textSecondary,
              ),
              const SizedBox(height: 16),
              Text(
                'No hay trabajadores en este turno',
                style: TextStyle(
                  fontSize: 16,
                  color: VentiqHomeTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Usa el botón + para agregar trabajadores',
                style: TextStyle(
                  fontSize: 14,
                  color: VentiqHomeTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Botón de acción múltiple
        if (_selectedWorkerIds.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            color: VentiqHomeTheme.primary.withOpacity(0.1),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_selectedWorkerIds.length} trabajador(es) seleccionado(s)',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: VentiqHomeTheme.textPrimary,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _registerSelectedWorkersExit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Registrar Salida'),
                ),
              ],
            ),
          ),

        // Lista de trabajadores
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadShiftWorkers,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _shiftWorkers.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final worker = _shiftWorkers[index];
                return _buildWorkerCard(worker);
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Calcular horas trabajadas en tiempo real
  double _calculateCurrentHours(ShiftWorker worker) {
    if (worker.horaSalida != null) {
      // Si ya tiene hora de salida, usar el valor calculado
      return worker.horasTrabajadas ?? 0.0;
    } else {
      // Si está activo, calcular desde entrada hasta ahora
      final now = DateTime.now();
      final duration = now.difference(worker.horaEntrada);
      return duration.inSeconds / 3600.0; // Convertir a horas
    }
  }

  Widget _buildWorkerCard(ShiftWorker worker) {
    final isSelected = _selectedWorkerIds.contains(worker.id);
    final isActive = worker.isActive;
    final currentHours = _calculateCurrentHours(worker);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side:
            isSelected
                ? const BorderSide(color: VentiqHomeTheme.primary, width: 2)
                : BorderSide.none,
      ),
      child: InkWell(
        onTap:
            isActive
                ? () {
                  setState(() {
                    if (isSelected) {
                      _selectedWorkerIds.remove(worker.id);
                    } else {
                      _selectedWorkerIds.add(worker.id!);
                    }
                  });
                }
                : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Checkbox para selección
                  if (isActive)
                    Checkbox(
                      value: isSelected,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selectedWorkerIds.add(worker.id!);
                          } else {
                            _selectedWorkerIds.remove(worker.id);
                          }
                        });
                      },
                      activeColor: VentiqHomeTheme.primary,
                    ),

                  // Avatar
                  CircleAvatar(
                    backgroundColor:
                        isActive
                            ? VentiqHomeTheme.primary.withOpacity(0.1)
                            : VentiqHomeTheme.border,
                    child: Icon(
                      Icons.person,
                      color:
                          isActive
                              ? VentiqHomeTheme.primary
                              : VentiqHomeTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Información del trabajador
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          worker.nombreCompleto,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: VentiqHomeTheme.textPrimary,
                          ),
                        ),
                        if (worker.rolTrabajador != null) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: VentiqHomeTheme.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              worker.rolTrabajador!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: VentiqHomeTheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Estado
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color:
                          isActive ? Colors.green[50] : VentiqHomeTheme.border,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isActive ? Icons.check_circle : Icons.logout,
                          size: 14,
                          color:
                              isActive
                                  ? Colors.green[700]
                                  : VentiqHomeTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isActive ? 'Activo' : 'Finalizado',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color:
                                isActive
                                    ? Colors.green[700]
                                    : VentiqHomeTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Horarios
              Row(
                children: [
                  Expanded(
                    child: _buildTimeInfo(
                      icon: Icons.login,
                      label: 'Entrada',
                      time: _formatTime(worker.horaEntrada),
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTimeInfo(
                      icon: Icons.logout,
                      label: 'Salida',
                      time:
                          worker.horaSalida != null
                              ? _formatTime(worker.horaSalida!)
                              : '--:--',
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTimeInfo(
                      icon: Icons.access_time,
                      label: 'Horas',
                      time: '${currentHours.toStringAsFixed(1)}h',
                      color: VentiqHomeTheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeInfo({
    required IconData icon,
    required String label,
    required String time,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: VentiqHomeTheme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          time,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: VentiqHomeTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime dateTime) {
    return DateFormat('HH:mm').format(dateTime.toLocal());
  }

  Future<void> _showAddWorkersDialog() async {
    try {
      // Obtener trabajadores disponibles
      final availableWorkers = await ShiftWorkersService.getAvailableWorkers();

      if (availableWorkers.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No hay trabajadores disponibles'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Filtrar trabajadores que ya están en el turno
      final currentWorkerIds = _shiftWorkers.map((w) => w.idTrabajador).toSet();
      final selectableWorkers =
          availableWorkers
              .where((w) => !currentWorkerIds.contains(w.id))
              .toList();

      if (selectableWorkers.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Todos los trabajadores ya están en el turno'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      if (!mounted) return;

      // Mostrar diálogo de selección
      final selectedIds = await showDialog<List<int>>(
        context: context,
        builder:
            (context) => _WorkerSelectionDialog(workers: selectableWorkers),
      );

      if (selectedIds != null && selectedIds.isNotEmpty) {
        await _addWorkersToShift(selectedIds);
      }
    } catch (e) {
      print('❌ Error mostrando diálogo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _addWorkersToShift(List<int> workerIds) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
      );

      final result = await ShiftWorkersService.addWorkersToShift(
        idTurno: _currentShiftId!,
        idsTrabajadores: workerIds,
      );

      if (mounted) {
        Navigator.pop(context); // Cerrar loading

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Operación completada'),
            backgroundColor:
                result['success'] == true ? Colors.green : Colors.red,
          ),
        );

        if (result['success'] == true) {
          await _loadShiftWorkers();
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Cerrar loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _registerSelectedWorkersExit() async {
    if (_selectedWorkerIds.isEmpty) return;

    // Confirmar acción
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Registrar Salida'),
            content: Text(
              '¿Registrar salida para ${_selectedWorkerIds.length} trabajador(es)?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Confirmar'),
              ),
            ],
          ),
    );

    if (confirm != true) return;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
      );

      final result = await ShiftWorkersService.registerWorkersExit(
        idsRegistros: _selectedWorkerIds.toList(),
      );

      if (mounted) {
        Navigator.pop(context); // Cerrar loading

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Operación completada'),
            backgroundColor:
                result['success'] == true ? Colors.green : Colors.red,
          ),
        );

        if (result['success'] == true) {
          setState(() {
            _selectedWorkerIds.clear();
          });
          await _loadShiftWorkers();
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Cerrar loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

// Diálogo de selección de trabajadores
class _WorkerSelectionDialog extends StatefulWidget {
  final List<AvailableWorker> workers;

  const _WorkerSelectionDialog({required this.workers});

  @override
  State<_WorkerSelectionDialog> createState() => _WorkerSelectionDialogState();
}

class _WorkerSelectionDialogState extends State<_WorkerSelectionDialog> {
  final Set<int> _selectedIds = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Seleccionar Trabajadores'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.workers.length,
          itemBuilder: (context, index) {
            final worker = widget.workers[index];
            final isSelected = _selectedIds.contains(worker.id);

            return CheckboxListTile(
              value: isSelected,
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    _selectedIds.add(worker.id);
                  } else {
                    _selectedIds.remove(worker.id);
                  }
                });
              },
              title: Text(worker.nombreCompleto),
              subtitle: worker.rol != null ? Text(worker.rol!) : null,
              activeColor: VentiqHomeTheme.primary,
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed:
              _selectedIds.isEmpty
                  ? null
                  : () => Navigator.pop(context, _selectedIds.toList()),
          style: ElevatedButton.styleFrom(
            backgroundColor: VentiqHomeTheme.primary,
            foregroundColor: Colors.white,
          ),
          child: Text('Agregar (${_selectedIds.length})'),
        ),
      ],
    );
  }
}
