import 'package:flutter/material.dart';

import '../../services/user_preferences_service.dart';

/// Lista de turnos offline (abiertos y cerrados pendientes de sync) con su
/// cuadre local, para que gerente/supervisor lo revise en full offline.
class AdminTurnosOfflineScreen extends StatefulWidget {
  const AdminTurnosOfflineScreen({super.key});

  @override
  State<AdminTurnosOfflineScreen> createState() =>
      _AdminTurnosOfflineScreenState();
}

class _AdminTurnosOfflineScreenState extends State<AdminTurnosOfflineScreen> {
  final _prefs = UserPreferencesService();
  bool _loading = true;
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cuadres offline'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _turnos.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No hay turnos offline pendientes de sincronizar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[700], fontSize: 16),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _turnos.length,
                    itemBuilder: (context, index) {
                      final t = _turnos[index];
                      final id = t['local_id']?.toString() ?? '';
                      final cuadre = _cuadres[id] ?? {};
                      final status = t['status']?.toString();
                      final color = _statusColor(status);
                      final diferencia =
                          (cuadre['diferencia'] as num?)?.toDouble() ?? 0.0;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _showDetail(t, cuadre),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _fmtFecha(t['fecha_apertura']),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: color.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: color.withOpacity(0.35),
                                        ),
                                      ),
                                      child: Text(
                                        _statusLabel(status),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: color,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Ventas: ${_fmtMoney(cuadre['ventas_totales'])}'
                                  ' · Esperado: ${_fmtMoney(cuadre['efectivo_esperado'])}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  status ==
                                          UserPreferencesService
                                              .offlineTurnoStatusClosedPending
                                      ? 'Final: ${_fmtMoney(cuadre['efectivo_final'])}'
                                          ' · Dif: ${_fmtMoney(diferencia)}'
                                      : 'Efectivo inicial: ${_fmtMoney(_efectivoInicialOf(t, cuadre))}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: diferencia.abs() > 0.01
                                        ? Colors.red[700]
                                        : Colors.grey[700],
                                    fontWeight: diferencia.abs() > 0.01
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  void _showDetail(
    Map<String, dynamic> turno,
    Map<String, dynamic> cuadre,
  ) {
    final status = turno['status']?.toString();
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
                if (status ==
                    UserPreferencesService.offlineTurnoStatusClosedPending) ...[
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
              ],
            );
          },
        );
      },
    );
  }

  Widget _row(String label, String value, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[700], fontSize: 14),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
              fontSize: 14,
              color: emphasize ? Colors.red[700] : const Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }
}
