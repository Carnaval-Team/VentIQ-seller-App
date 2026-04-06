import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../models/worker_models.dart';
import '../../models/hr/hr_audit_log.dart';
import '../../services/worker_service.dart';
import '../../services/store_service.dart';
import '../../services/hr/hr_salary_report_service.dart';
import '../../widgets/hr/hr_drawer.dart';

class HRWorkerConfigScreen extends StatefulWidget {
  const HRWorkerConfigScreen({super.key});

  @override
  State<HRWorkerConfigScreen> createState() => _HRWorkerConfigScreenState();
}

class _HRWorkerConfigScreenState extends State<HRWorkerConfigScreen> {
  bool _isLoading = true;
  int? _storeId;
  String? _userUuid;

  List<WorkerData> _workers = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

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
      print('❌ Error inicializando config: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadWorkers() async {
    if (_storeId == null || _userUuid == null) return;
    setState(() => _isLoading = true);

    try {
      final workers = await WorkerService.getWorkersByStore(_storeId!, _userUuid!);
      if (mounted) {
        setState(() {
          _workers = workers;
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

  List<WorkerData> get _filteredWorkers {
    if (_searchQuery.isEmpty) return _workers;
    final query = _searchQuery.toLowerCase();
    return _workers.where((w) {
      return w.nombreCompleto.toLowerCase().contains(query) ||
          w.rolNombre.toLowerCase().contains(query);
    }).toList();
  }

  void _showEditSheet(WorkerData worker) {
    final salarioController = TextEditingController(
      text: worker.salarioHoras.toStringAsFixed(2),
    );
    final pprController = TextEditingController(
      text: worker.pagoPorResultado.toStringAsFixed(2),
    );
    final motivoController = TextEditingController();
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: AppColors.primary.withOpacity(0.1),
                          child: Text(
                            worker.nombres.isNotEmpty ? worker.nombres[0].toUpperCase() : '?',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                worker.nombreCompleto,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                              Text(
                                worker.rolNombre,
                                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),

                    // Salario por hora
                    const Text(
                      'Salario por hora (\$/h)',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: salarioController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        prefixText: '\$ ',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Pago por resultado
                    const Text(
                      'Pago por resultado (PPR)',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: pprController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        prefixText: '\$ ',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Motivo
                    const Text(
                      'Motivo del cambio',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: motivoController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'Opcional: motivo del ajuste...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Boton guardar
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isSaving
                            ? null
                            : () async {
                                final newSalario = double.tryParse(salarioController.text) ?? 0;
                                final newPPR = double.tryParse(pprController.text) ?? 0;
                                final motivo = motivoController.text.trim().isEmpty
                                    ? null
                                    : motivoController.text.trim();

                                setSheetState(() => isSaving = true);

                                try {
                                  await HRSalaryReportService.updateWorkerSalary(
                                    workerId: worker.trabajadorId,
                                    storeId: _storeId!,
                                    salarioHoras: newSalario,
                                    pagoPorResultado: newPPR,
                                    modificadoPor: _userUuid!,
                                    motivo: motivo,
                                  );

                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (mounted) {
                                    ScaffoldMessenger.of(this.context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Salario actualizado exitosamente'),
                                        backgroundColor: AppColors.success,
                                      ),
                                    );
                                    await _loadWorkers();
                                  }
                                } catch (e) {
                                  setSheetState(() => isSaving = false);
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
                                    );
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text('Guardar Cambios', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Historial de auditoria
                    const Text(
                      'Historial de cambios',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    FutureBuilder<List<HRAuditLog>>(
                      future: HRSalaryReportService.getAuditLog(
                        workerId: worker.trabajadorId,
                        storeId: _storeId!,
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }

                        final logs = snapshot.data ?? [];
                        if (logs.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              'Sin cambios registrados',
                              style: TextStyle(color: Colors.grey[500], fontSize: 13),
                            ),
                          );
                        }

                        return ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: logs.length > 10 ? 10 : logs.length,
                          itemBuilder: (context, index) {
                            final log = logs[index];
                            final dateStr = DateFormat('dd/MM/yy HH:mm').format(log.createdAt);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.history, size: 16, color: Colors.grey[400]),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${log.campoLabel}: ${log.valorAnterior ?? "N/A"} -> ${log.valorNuevo ?? "N/A"}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        Row(
                                          children: [
                                            Text(
                                              dateStr,
                                              style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                                            ),
                                            if (log.motivo != null && log.motivo!.isNotEmpty) ...[
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  '- ${log.motivo}',
                                                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Configurar Trabajador',
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
                // Search bar
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.white,
                  child: TextField(
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
                ),

                // Workers list
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
                                    : 'No hay trabajadores',
                                style: TextStyle(color: Colors.grey[500], fontSize: 15),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 8, bottom: 16),
                          itemCount: _filteredWorkers.length,
                          itemBuilder: (context, index) {
                            final worker = _filteredWorkers[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: ListTile(
                                onTap: () => _showEditSheet(worker),
                                leading: CircleAvatar(
                                  radius: 20,
                                  backgroundColor: AppColors.primary.withOpacity(0.1),
                                  child: Text(
                                    worker.nombres.isNotEmpty ? worker.nombres[0].toUpperCase() : '?',
                                    style: TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  worker.nombreCompleto,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                ),
                                subtitle: Row(
                                  children: [
                                    Text(
                                      '\$${worker.salarioHoras.toStringAsFixed(2)}/h',
                                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                    ),
                                    if (worker.pagoPorResultado > 0) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: AppColors.success.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'PPR \$${worker.pagoPorResultado.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: AppColors.success,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
