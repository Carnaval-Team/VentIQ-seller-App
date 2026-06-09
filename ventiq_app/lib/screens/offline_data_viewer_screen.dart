import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/user_preferences_service.dart';

/// Visor de diagnóstico (solo lectura) de los datos guardados para trabajar
/// offline. Entrada oculta en el drawer, visible solo para superadmins.
///
/// Muestra cada clave de SharedPreferences relacionada con el modo offline con
/// su conteo y su contenido JSON formateado (expandible). No modifica nada.
class OfflineDataViewerScreen extends StatefulWidget {
  const OfflineDataViewerScreen({Key? key}) : super(key: key);

  @override
  State<OfflineDataViewerScreen> createState() =>
      _OfflineDataViewerScreenState();
}

class _OfflineDataViewerScreenState extends State<OfflineDataViewerScreen> {
  final _prefs = UserPreferencesService();
  bool _loading = true;
  bool _offlineModeEnabled = false;

  /// Secciones a mostrar: título, conteo (o null si no aplica) y el valor.
  final List<_OfflineSection> _sections = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final sections = <_OfflineSection>[];

    Future<void> add(
      String title,
      Future<dynamic> Function() getter,
    ) async {
      try {
        final value = await getter();
        sections.add(_OfflineSection(title: title, value: value));
      } catch (e) {
        sections.add(_OfflineSection(title: title, value: 'ERROR: $e'));
      }
    }

    _offlineModeEnabled = await _safeBool(_prefs.isOfflineModeEnabled());

    // offline_data desglosado (catálogo) + claves de trabajo offline.
    final offlineData = await _safeMap(_prefs.getOfflineData());
    sections.add(
      _OfflineSection(
        title: 'offline_data: categories',
        value: offlineData?['categories'],
      ),
    );
    sections.add(
      _OfflineSection(
        title: 'offline_data: products (por categoría)',
        value: offlineData?['products'],
      ),
    );
    sections.add(
      _OfflineSection(
        title: 'offline_data: payment_methods',
        value: offlineData?['payment_methods'],
      ),
    );
    sections.add(
      _OfflineSection(
        title: 'offline_data: promotions',
        value: offlineData?['promotions'],
      ),
    );

    // pending_orders con desglose: realmente pendientes (synced != true) vs
    // ya sincronizadas (conservadas en local hasta recargar/purgar).
    try {
      final orders = await _prefs.getPendingOrders();
      final noSync =
          orders.where((o) => o['synced'] != true).toList();
      final yaSync = orders.where((o) => o['synced'] == true).toList();
      sections.add(
        _OfflineSection(
          title:
              'pending_orders — ${noSync.length} sin sincronizar, '
              '${yaSync.length} ya sincronizadas',
          value: orders,
        ),
      );
    } catch (e) {
      sections.add(
        _OfflineSection(title: 'pending_orders', value: 'ERROR: $e'),
      );
    }
    await add('pending_operations', _prefs.getPendingOperations);
    await add('offline_turno', _prefs.getOfflineTurno);
    await add('egresos_offline (pendientes)', _prefs.getEgresosOffline);
    await add('egresos_cache', _prefs.getEgresosCache);
    await add('offline_users', _prefs.getOfflineUsers);
    await add('turno_resumen_cache', _prefs.getTurnoResumenCache);
    await add('resumen_cierre_cache', _prefs.getResumenCierreCache);

    if (mounted) {
      setState(() {
        _sections
          ..clear()
          ..addAll(sections);
        _loading = false;
      });
    }
  }

  Future<bool> _safeBool(Future<bool> f) async {
    try {
      return await f;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> _safeMap(Future<Map<String, dynamic>?> f) async {
    try {
      return await f;
    } catch (_) {
      return null;
    }
  }

  /// Cuenta elementos si el valor es lista o mapa; null si no aplica.
  int? _countOf(dynamic value) {
    if (value is List) return value.length;
    if (value is Map) return value.length;
    return null;
  }

  String _pretty(dynamic value) {
    if (value == null) return 'null (sin datos)';
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Datos Offline'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  Card(
                    color:
                        _offlineModeEnabled
                            ? Colors.orange[50]
                            : Colors.green[50],
                    child: ListTile(
                      leading: Icon(
                        _offlineModeEnabled
                            ? Icons.cloud_off
                            : Icons.cloud_done,
                        color:
                            _offlineModeEnabled ? Colors.orange : Colors.green,
                      ),
                      title: Text(
                        'Modo offline: '
                        '${_offlineModeEnabled ? "ACTIVADO" : "Desactivado"}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('${_sections.length} secciones'),
                    ),
                  ),
                  ..._sections.map(_buildSectionTile),
                ],
              ),
    );
  }

  Widget _buildSectionTile(_OfflineSection section) {
    final count = _countOf(section.value);
    final jsonText = _pretty(section.value);
    final hasData =
        section.value != null &&
        !(section.value is List && (section.value as List).isEmpty) &&
        !(section.value is Map && (section.value as Map).isEmpty);

    return Card(
      child: ExpansionTile(
        leading: Icon(
          hasData ? Icons.folder : Icons.folder_open,
          color: hasData ? Colors.blue : Colors.grey,
        ),
        title: Text(
          section.title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          count != null ? '$count elementos' : (hasData ? 'con datos' : 'vacío'),
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copiar'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: jsonText));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Copiado: ${section.title}'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              jsonText,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineSection {
  final String title;
  final dynamic value;

  _OfflineSection({required this.title, required this.value});
}
