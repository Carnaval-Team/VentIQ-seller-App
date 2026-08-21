import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/auto_sync_service.dart';
import '../../services/device_offline_prep_service.dart';
import '../../services/user_preferences_service.dart';

/// Sync + registro local de admin/vendedores para full offline en el dispositivo.
class AdminPrepareOfflineScreen extends StatefulWidget {
  const AdminPrepareOfflineScreen({super.key});

  @override
  State<AdminPrepareOfflineScreen> createState() =>
      _AdminPrepareOfflineScreenState();
}

class _AdminPrepareOfflineScreenState extends State<AdminPrepareOfflineScreen> {
  final _prep = DeviceOfflinePrepService();
  final _prefs = UserPreferencesService();
  final _autoSync = AutoSyncService();

  bool _loading = true;
  bool _syncing = false;
  String _status = '';
  String? _error;
  List<Map<String, dynamic>> _sellers = [];
  final Map<String, TextEditingController> _passwordCtrls = {};
  final _adminPasswordCtrl = TextEditingController();
  bool _adminRegistered = false;
  bool _ready = false;

  String _syncStepLabel = '';
  int _syncCurrent = 0;
  int _syncTotal = 0;
  StreamSubscription<AutoSyncEvent>? _syncSub;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _adminPasswordCtrl.dispose();
    for (final c in _passwordCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _prep.assertCanPrepare();
      _ready = await _prefs.isDeviceFullOfflineReady();
      await _refreshSellers();
      final email = await _prefs.getUserEmail();
      final storeId = await _prefs.getIdTienda();
      if (storeId != null && email != null) {
        final users = await _prefs.getOfflineUsersForStore(storeId);
        final adminCreds = await _prefs.getDeviceFullOfflineAdminCredentials();
        final hasAdminInUsers = users.any(
          (u) =>
              u['email']?.toString().toLowerCase() == email.toLowerCase() &&
              (u['entryRole'] == 'gerente' || u['entryRole'] == 'supervisor'),
        );
        _adminRegistered = hasAdminInUsers &&
            (adminCreds['email']?.isNotEmpty ?? false) &&
            (adminCreds['password']?.isNotEmpty ?? false);
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshSellers() async {
    final list = await _prep.listStoreSellers();
    for (final s in list) {
      final email = s['email']?.toString() ?? '';
      if (email.isNotEmpty && !_passwordCtrls.containsKey(email)) {
        _passwordCtrls[email] = TextEditingController();
      }
    }
    if (mounted) setState(() => _sellers = list);
  }

  Future<void> _runSync() async {
    setState(() {
      _syncing = true;
      _status = 'Sincronizando...';
      _error = null;
      _syncStepLabel = 'Iniciando...';
      _syncCurrent = 0;
      _syncTotal = DeviceOfflinePrepService.prepModules.length;
    });

    await _syncSub?.cancel();
    _syncSub = _autoSync.syncEventStream.listen((event) {
      if (event.type == AutoSyncEventType.syncProgress && mounted) {
        setState(() {
          _syncStepLabel = event.message;
          _syncCurrent = event.progressCurrent ?? _syncCurrent;
          _syncTotal = event.progressTotal ?? _syncTotal;
          _status =
              'Sincronizando: $_syncStepLabel ($_syncCurrent/$_syncTotal)';
        });
      }
    });

    try {
      final result = await _prep.runPrepSync(
        ensurePassword: _adminPasswordCtrl.text.trim().isNotEmpty
            ? _adminPasswordCtrl.text.trim()
            : null,
      );
      final hasData = await _prefs.hasOfflineData();
      setState(() {
        _syncCurrent = _syncTotal;
        _status = result.success
            ? 'Sync OK (${result.syncedItems.length} módulos). '
                'Datos offline: ${hasData ? "listos" : "incompletos"}'
            : 'Sync con errores: ${result.errors.join("; ")}';
      });
      await _refreshSellers();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      await _syncSub?.cancel();
      _syncSub = null;
      if (mounted) setState(() => _syncing = false);
    }
  }

  Widget _buildSyncProgress() {
    if (!_syncing) return const SizedBox.shrink();
    final fraction =
        _syncTotal > 0 ? (_syncCurrent / _syncTotal).clamp(0.0, 1.0) : null;
    final remaining =
        _syncTotal > 0 ? (_syncTotal - _syncCurrent).clamp(0, _syncTotal) : 0;

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _syncStepLabel.isEmpty ? 'Sincronizando...' : _syncStepLabel,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _syncCurrent == 0 ? null : fraction,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 6),
          Text(
            _syncTotal > 0
                ? 'Paso $_syncCurrent de $_syncTotal'
                    '${remaining > 0 ? ' · Faltan $remaining' : ''}'
                : 'Preparando módulos...',
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }

  Future<void> _registerAdmin() async {
    setState(() {
      _status = 'Registrando administrador...';
      _error = null;
    });
    try {
      await _prep.registerCurrentAdmin(password: _adminPasswordCtrl.text);
      setState(() {
        _adminRegistered = true;
        _status = 'Administrador registrado offline';
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _registerSeller(Map<String, dynamic> seller) async {
    final email = seller['email']?.toString() ?? '';
    final pwd = _passwordCtrls[email]?.text ?? '';
    setState(() {
      _status = 'Validando $email...';
      _error = null;
    });
    try {
      await _prep.registerSellerWithPassword(
        sellerProfile: seller,
        password: pwd,
      );
      _passwordCtrls[email]?.clear();
      await _refreshSellers();
      setState(() => _status = 'Vendedor $email registrado');
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _finish() async {
    try {
      await _prep.markReadyIfPossible();
      final offlineOn = await _prefs.isOfflineModeEnabled();
      final hasData = await _prefs.hasOfflineData();
      if (!mounted) return;
      setState(() {
        _ready = true;
        _status =
            'Dispositivo listo. Modo offline app: ${offlineOn ? "ON" : "OFF"}; '
            'datos: ${hasData ? "OK" : "faltan"}';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            offlineOn
                ? 'Modo offline activado. Al cerrar sesión podrás elegir usuario localmente.'
                : 'Dispositivo marcado, pero el modo offline no quedó activo. Revisa el sync.',
          ),
          backgroundColor: offlineOn ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preparar dispositivo offline'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _sellers.isEmpty && !_adminRegistered
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_ready)
                      Card(
                        color: Colors.green[50],
                        child: const ListTile(
                          leading: Icon(Icons.check_circle, color: Colors.green),
                          title: Text('Dispositivo en modo full offline'),
                          subtitle: Text(
                            'Cerrar sesión abrirá el selector local de usuarios',
                          ),
                        ),
                      ),
                    const Text(
                      '1. Contraseña del administrador',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Necesaria para el sync (credenciales offline) y el registro local.',
                      style: TextStyle(color: Colors.grey[700], fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _adminPasswordCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: _adminRegistered
                            ? 'Actualizar contraseña admin'
                            : 'Contraseña del admin',
                        border: const OutlineInputBorder(),
                        suffixIcon: _adminRegistered
                            ? const Icon(Icons.check, color: Colors.green)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _registerAdmin,
                      child: Text(
                        _adminRegistered
                            ? 'Actualizar admin offline'
                            : 'Registrar admin offline',
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '2. Sincronizar catálogo y licencia',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _syncing ? null : _runSync,
                      icon: _syncing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                      label: Text(
                        _syncing ? 'Sincronizando...' : 'Sincronizar ahora',
                      ),
                    ),
                    _buildSyncProgress(),
                    const SizedBox(height: 16),
                    const Text(
                      '3. Registrar vendedores (email + contraseña)',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Supabase no entrega contraseñas: escríbela una vez por vendedor.',
                      style: TextStyle(color: Colors.grey[700], fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    if (_sellers.isEmpty)
                      const Text('No hay vendedores en esta tienda.'),
                    ..._sellers.map(_buildSellerTile),
                    if (_status.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(_status, style: TextStyle(color: Colors.blue[800])),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _finish,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[700],
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      icon: const Icon(Icons.phonelink_setup),
                      label: const Text('Marcar dispositivo listo'),
                    ),
                  ],
                ),
    );
  }

  Widget _buildSellerTile(Map<String, dynamic> seller) {
    final email = seller['email']?.toString() ?? '';
    final name =
        '${seller['nombres'] ?? ''} ${seller['apellidos'] ?? ''}'.trim();
    final registered = seller['registeredOffline'] == true;
    final ctrl = _passwordCtrls[email];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? 'Sin nombre' : name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        email.isEmpty ? 'Sin email (user_mail)' : email,
                        style: TextStyle(color: Colors.grey[700], fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (registered)
                  const Chip(
                    label: Text('Listo'),
                    backgroundColor: Color(0xFFE8F5E9),
                  ),
              ],
            ),
            if (email.isNotEmpty && ctrl != null) ...[
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Contraseña',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _registerSeller(seller),
                  child: Text(registered ? 'Actualizar' : 'Registrar'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
