import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auto_sync_service.dart';
import '../services/connectivity_service.dart';

/// Diálogo para sincronizar módulos de forma selectiva (subir / bajar).
/// La licencia siempre queda seleccionada e incluida en descargas.
class SelectiveSyncDialog extends StatefulWidget {
  const SelectiveSyncDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const SelectiveSyncDialog(),
    );
  }

  @override
  State<SelectiveSyncDialog> createState() => _SelectiveSyncDialogState();
}

class _SelectiveSyncDialogState extends State<SelectiveSyncDialog> {
  final AutoSyncService _autoSync = AutoSyncService();
  final ConnectivityService _connectivity = ConnectivityService();

  late final Set<SyncModule> _selected;
  bool _running = false;
  String _progressLabel = '';
  int _progressCurrent = 0;
  int _progressTotal = 0;
  SyncResult? _result;
  StreamSubscription<AutoSyncEvent>? _sub;

  static const _uploadModules = [
    SyncModule.uploadSales,
    SyncModule.uploadEgresos,
    SyncModule.uploadTurno,
    SyncModule.uploadShiftWorkers,
    SyncModule.uploadAdminOps,
  ];

  static const _downloadModules = [
    SyncModule.license,
    SyncModule.storeConfig,
    SyncModule.credentials,
    SyncModule.paymentMethods,
    SyncModule.promotions,
    SyncModule.categories,
    SyncModule.products,
    SyncModule.layouts,
    SyncModule.turno,
    SyncModule.egresos,
    SyncModule.orders,
  ];

  @override
  void initState() {
    super.initState();
    _selected = {
      ..._uploadModules,
      ..._downloadModules,
    };
    _sub = _autoSync.syncEventStream.listen((event) {
      if (event.type == AutoSyncEventType.syncProgress && mounted) {
        setState(() {
          _progressLabel = event.message;
          _progressCurrent = event.progressCurrent ?? _progressCurrent;
          _progressTotal = event.progressTotal ?? _progressTotal;
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    if (!_connectivity.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Se requiere conexión a internet para sincronizar'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _running = true;
      _progressLabel = 'Iniciando...';
      _progressCurrent = 0;
      _progressTotal = _selected.length;
      _result = null;
    });

    final result = await _autoSync.syncModules(_selected);

    if (!mounted) return;
    setState(() {
      _running = false;
      _result = result;
      _progressLabel = result.success ? 'Completado' : 'Completado con errores';
      if (_progressTotal > 0) {
        _progressCurrent = _progressTotal;
      }
    });
  }

  void _toggle(SyncModule module, bool? value) {
    if (module.isRequired) return;
    setState(() {
      if (value == true) {
        _selected.add(module);
      } else {
        _selected.remove(module);
      }
    });
  }

  double get _fraction {
    if (_progressTotal <= 0) return _running ? 0 : 1;
    return (_progressCurrent / _progressTotal).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final remaining =
        _running && _progressTotal > 0
            ? (_progressTotal - _progressCurrent).clamp(0, _progressTotal)
            : 0;

    return AlertDialog(
      title: const Text('Sincronizar por módulos'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Elige qué subir al servidor y qué bajar al dispositivo. '
                'La licencia se incluye siempre al descargar.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              _sectionHeader('Subir (upload)', Icons.cloud_upload_outlined),
              ..._uploadModules.map(_checkbox),
              const SizedBox(height: 12),
              _sectionHeader('Bajar (download)', Icons.cloud_download_outlined),
              ..._downloadModules.map(_checkbox),
              if (_running || _result != null) ...[
                const SizedBox(height: 16),
                const Divider(),
                Text(
                  _progressLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: _running && _progressCurrent == 0 ? null : _fraction,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 6),
                Text(
                  _running
                      ? (_progressTotal > 0
                          ? 'Paso $_progressCurrent de $_progressTotal'
                              '${remaining > 0 ? ' · Faltan $remaining' : ''}'
                          : 'Sincronizando...')
                      : (_result?.success == true
                          ? '100% completado'
                          : 'Finalizado'),
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
                if (_result != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _result!.success
                        ? '✅ ${_result!.syncedItems.length} módulos OK '
                            '(${_result!.duration.inSeconds}s)'
                        : '⚠️ Errores: ${_result!.errors.join("; ")}',
                    style: TextStyle(
                      color:
                          _result!.success
                              ? Colors.green.shade800
                              : Colors.orange.shade900,
                      fontSize: 13,
                    ),
                  ),
                  if (_result!.syncedItems.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _result!.syncedItems.join(', '),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _running ? null : () => Navigator.of(context).pop(),
          child: Text(_result != null ? 'Cerrar' : 'Cancelar'),
        ),
        ElevatedButton.icon(
          onPressed: _running || _selected.isEmpty ? null : _run,
          icon: const Icon(Icons.sync, size: 18),
          label: Text(_running ? 'Sincronizando...' : 'Sincronizar'),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF194B8C)),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _checkbox(SyncModule module) {
    final selected = _selected.contains(module);
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: selected,
      onChanged: module.isRequired || _running
          ? null
          : (v) => _toggle(module, v),
      title: Text(
        module.label,
        style: TextStyle(
          fontSize: 13,
          color: module.isRequired ? Colors.black54 : null,
        ),
      ),
      subtitle: module.isRequired
          ? const Text(
              'Siempre incluida al bajar datos',
              style: TextStyle(fontSize: 11),
            )
          : null,
    );
  }
}
