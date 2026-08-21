import 'package:flutter/material.dart';

import '../../services/admin_ticket_printer_service.dart';
import '../../services/auto_sync_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/user_preferences_service.dart';

/// Lista de turnos offline (abiertos y cerrados pendientes de sync) con su
/// cuadre local. El gerente puede subir la cola al servidor cuando hay red.
class AdminTurnosOfflineScreen extends StatefulWidget {
  const AdminTurnosOfflineScreen({super.key});

  @override
  State<AdminTurnosOfflineScreen> createState() =>
      _AdminTurnosOfflineScreenState();
}

class _AdminTurnosOfflineScreenState extends State<AdminTurnosOfflineScreen> {
  final _prefs = UserPreferencesService();
  final _autoSync = AutoSyncService();
  final _connectivity = ConnectivityService();

  bool _loading = true;
  bool _syncing = false;
  List<Map<String, dynamic>> _turnos = [];
  final Map<String, Map<String, dynamic>> _cuadres = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final pending = await _prefs.getOfflineTurnosPendingSync();
      final cuadres = <String, Map<String, dynamic>>{};
      for (final t in pending) {
        final id = t['local_id']?.toString() ?? '';
        if (id.isEmpty) continue;
        cuadres[id] = await _prefs.getOfflineTurnoCuadre(t);
      }
      if (!mounted) return;
      setState(() {
        _turnos = pending;
        _cuadres
          ..clear()
          ..addAll(cuadres);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando turnos: $e')),
      );
    }
  }

  int get _closedPendingCount => _turnos
      .where(
        (t) =>
            t['status']?.toString() ==
            UserPreferencesService.offlineTurnoStatusClosedPending,
      )
      .length;

  Future<void> _syncTurnos() async {
    if (_syncing) return;

    if (!_connectivity.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sin conexión. Conéctate a internet para sincronizar turnos.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_turnos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay turnos pendientes de sincronizar')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sincronizar turnos'),
        content: Text(
          'Se subirán ${_turnos.length} turno(s) offline '
          '(apertura, ventas, egresos y cierres pendientes) al servidor.\n\n'
          'Cerrados pendientes: $_closedPendingCount.\n'
          'El modo offline se reactivará al terminar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sincronizar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _syncing = true);
    try {
      final result = await _autoSync.syncOfflineTurnosFromAdmin();
      if (!mounted) return;

      final queue = result['queue'];
      final q = queue is Map ? Map<String, dynamic>.from(queue) : <String, dynamic>{};
      final closedRemaining = (q['closed_remaining'] as num?)?.toInt() ?? 0;
      final cierres = (q['cierres'] as num?)?.toInt() ?? 0;

      final msg = closedRemaining > 0
          ? 'Parcial · cierres OK $cierres, '
              'aún pendientes de cierre $closedRemaining. Reintenta.'
          : 'Sync OK · aperturas ${q['turnos'] ?? 0}, '
              'ventas ${q['sales'] ?? 0}, egresos ${q['egresos'] ?? 0}, '
              'cierres $cierres';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: closedRemaining > 0 ? Colors.orange : Colors.green,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al sincronizar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  String _fmtMoney(dynamic v) {
    final n = (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;
    return '\$${n.toStringAsFixed(2)}';
  }

  dynamic _efectivoInicialOf(
    Map<String, dynamic> t,
    Map<String, dynamic> cuadre,
  ) {
    if (cuadre['efectivo_inicial'] != null) return cuadre['efectivo_inicial'];
    final apertura = t['apertura'];
    if (apertura is Map) return apertura['efectivo_inicial'];
    return 0;
  }

  String _fmtFecha(dynamic raw) {
    if (raw == null) return '—';
    try {
      final dt = DateTime.parse(raw.toString());
      final local = dt.toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${two(local.day)}/${two(local.month)}/${local.year} '
          '${two(local.hour)}:${two(local.minute)}';
    } catch (_) {
      return raw.toString();
    }
  }

  String _statusLabel(String? status) {
    switch (status) {
      case UserPreferencesService.offlineTurnoStatusOpen:
        return 'Abierto';
      case UserPreferencesService.offlineTurnoStatusClosedPending:
        return 'Cerrado · pendiente sync';
      default:
        return status ?? '—';
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case UserPreferencesService.offlineTurnoStatusOpen:
        return Colors.orange;
      case UserPreferencesService.offlineTurnoStatusClosedPending:
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSync = _turnos.isNotEmpty && !_loading && !_syncing;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cuadres offline'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Sincronizar turnos al servidor',
            onPressed: canSync ? _syncTurnos : null,
            icon: _syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.cloud_upload_outlined),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: (_loading || _syncing) ? null : _load,
          ),
        ],
      ),
      floatingActionButton: canSync
          ? FloatingActionButton.extended(
              onPressed: _syncTurnos,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: Text(
                _closedPendingCount > 0
                    ? 'Sync ($_closedPendingCount cierres)'
                    : 'Sincronizar',
              ),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _turnos.isEmpty
              ? Center(
                  child: Text(
                    'No hay turnos offline pendientes de sincronizar.',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                )
              : Column(
                  children: [
                    if (_syncing)
                      const LinearProgressIndicator(minHeight: 3),
                    Material(
                      color: Colors.blue.shade50,
                      child: ListTile(
                        leading: Icon(
                          Icons.info_outline,
                          color: Colors.blue.shade700,
                        ),
                        title: Text(
                          '${_turnos.length} turno(s) en cola · '
                          '$_closedPendingCount cerrado(s) por subir',
                        ),
                        subtitle: Text(
                          _connectivity.isConnected
                              ? 'Hay red: puedes sincronizar desde aquí'
                              : 'Sin red: el sync estará disponible al conectarte',
                        ),
                        dense: true,
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          itemCount: _turnos.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final t = _turnos[index];
                            final id = t['local_id']?.toString() ?? '';
                            final cuadre = _cuadres[id] ?? {};
                            final status = t['status']?.toString();
                            final diff =
                                (cuadre['diferencia'] as num?)?.toDouble() ??
                                    0.0;
                            final closedPending = status ==
                                UserPreferencesService
                                    .offlineTurnoStatusClosedPending;

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    _statusColor(status).withValues(alpha: 0.15),
                                child: Icon(
                                  closedPending
                                      ? Icons.cloud_upload_outlined
                                      : Icons.lock_open,
                                  color: _statusColor(status),
                                ),
                              ),
                              title: Text(
                                'TPV ${t['id_tpv'] ?? '—'} · ${_statusLabel(status)}',
                              ),
                              subtitle: Text(
                                'Apertura: ${_fmtFecha(t['fecha_apertura'])}\n'
                                'Ventas: ${_fmtMoney(cuadre['ventas_totales'])}'
                                ' · Esperado: ${_fmtMoney(cuadre['efectivo_esperado'])}',
                              ),
                              isThreeLine: true,
                              trailing: closedPending
                                  ? Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          'Diff ${_fmtMoney(diff)}',
                                          style: TextStyle(
                                            color: diff.abs() < 0.01
                                                ? Colors.green
                                                : Colors.red,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          'Final: ${_fmtMoney(cuadre['efectivo_final'])}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    )
                                  : Text(
                                      'Efectivo inicial: ${_fmtMoney(_efectivoInicialOf(t, cuadre))}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                              onTap: () => _showDetail(t, cuadre),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  void _showDetail(
    Map<String, dynamic> turno,
    Map<String, dynamic> cuadre,
  ) {
    final status = turno['status']?.toString();
    final closedPending =
        status == UserPreferencesService.offlineTurnoStatusClosedPending;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Cuadre del turno',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  _statusLabel(status),
                  style: TextStyle(color: _statusColor(status)),
                ),
                if (cuadre['reconstruido'] == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Resumen reconstruido desde ventas locales (cierre anterior a esta versión).',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
                const SizedBox(height: 16),
                _row('Apertura', _fmtFecha(turno['fecha_apertura'])),
                _row('Cierre', _fmtFecha(turno['fecha_cierre'])),
                const Divider(height: 24),
                _row('Efectivo inicial', _fmtMoney(cuadre['efectivo_inicial'])),
                _row('Ventas totales', _fmtMoney(cuadre['ventas_totales'])),
                _row('Efectivo ventas', _fmtMoney(cuadre['total_efectivo'])),
                _row(
                  'Transferencias',
                  _fmtMoney(cuadre['total_transferencias']),
                ),
                _row('Egresos efectivo', _fmtMoney(cuadre['egresos_efectivo'])),
                _row(
                  'Egresos digitales',
                  _fmtMoney(cuadre['egresos_digitales']),
                ),
                _row('Efectivo esperado', _fmtMoney(cuadre['efectivo_esperado'])),
                if (closedPending) ...[
                  _row('Efectivo final', _fmtMoney(cuadre['efectivo_final'])),
                  _row(
                    'Diferencia',
                    _fmtMoney(cuadre['diferencia']),
                    emphasize: true,
                  ),
                ],
                const Divider(height: 24),
                _row(
                  'Operaciones',
                  '${cuadre['operaciones_totales'] ?? 0}',
                ),
                _row(
                  'Productos vendidos',
                  '${cuadre['productos_vendidos'] ?? 0}',
                ),
                _row(
                  'Ticket promedio',
                  _fmtMoney(cuadre['ticket_promedio']),
                ),
                const SizedBox(height: 16),
                if (closedPending) ...[
                  FilledButton.icon(
                    onPressed: _syncing
                        ? null
                        : () {
                            Navigator.pop(context);
                            _syncTurnos();
                          },
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Sincronizar cola de turnos'),
                  ),
                  const SizedBox(height: 8),
                ],
                // Diagnóstico/resolución manual: disponible tanto para
                // turnos "Cerrado · pendiente sync" atascados (el replay
                // los rechaza siempre por mismatch de TPV) como para
                // turnos que quedaron "Abierto" localmente por días sin
                // poder sincronizar la apertura.
                OutlinedButton.icon(
                  onPressed: _syncing
                      ? null
                      : () {
                          Navigator.pop(context);
                          _forceResolveTurno(turno);
                        },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.deepOrange,
                    side: const BorderSide(color: Colors.deepOrange),
                  ),
                  icon: const Icon(Icons.build_circle_outlined),
                  label: Text(
                    closedPending
                        ? 'Diagnosticar / forzar cierre'
                        : 'Diagnosticar turno atascado',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    await AdminTicketPrinterService().confirmAndPrint(
                      context,
                      title: 'Cuadre turno',
                      lines: AdminTicketPrinterService.cuadreLines(
                        turno: turno,
                        cuadre: cuadre,
                      ),
                    );
                  },
                  icon: const Icon(Icons.print),
                  label: const Text('Imprimir cuadre'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Diagnostica un turno `closed_pending_sync` atascado (p.ej. el replay
  /// automático lo rechaza siempre con "no se encontró un turno abierto
  /// para el TPV X") y, si el admin confirma, intenta resolverlo: cerrarlo
  /// con el TPV real del servidor si sigue abierto ahí, o descartarlo de la
  /// cola local si el servidor ya no lo tiene abierto.
  Future<void> _forceResolveTurno(Map<String, dynamic> turno) async {
    final localId = turno['local_id']?.toString() ?? '';
    if (localId.isEmpty) return;

    if (!_connectivity.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sin conexión. Conéctate a internet para diagnosticar.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    Map<String, dynamic> diag;
    try {
      diag = await _autoSync.diagnoseStuckTurno(localId);
    } catch (e) {
      diag = {'found': true, 'message': 'Error diagnosticando: $e'};
    }

    if (!mounted) return;
    Navigator.pop(context); // Cerrar el loading.

    final canAct = diag['found'] == true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Diagnóstico del turno'),
        content: Text(diag['message']?.toString() ?? 'Sin información.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cerrar'),
          ),
          if (canAct)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Forzar resolución'),
            ),
        ],
      ),
    );
    if (confirmed != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    Map<String, dynamic> result;
    try {
      result = await _autoSync.forceResolveStuckTurno(localId);
    } catch (e) {
      result = {'success': false, 'message': 'Error: $e'};
    }

    if (!mounted) return;
    Navigator.pop(context); // Cerrar el loading.

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result['message']?.toString() ?? 'Sin resultado'),
        backgroundColor:
            result['success'] == true ? Colors.green : Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
    await _load();
  }

  Widget _row(String label, String value, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: Colors.grey[700])),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
